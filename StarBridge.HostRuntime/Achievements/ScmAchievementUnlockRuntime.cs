using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Achievements;

internal sealed class ScmAchievementUnlockRuntime : IDisposable
{
    internal const int MaximumRereads = 3;
    internal static readonly IReadOnlyList<TimeSpan> RereadOffsets = Array.AsReadOnly(new[] {
        TimeSpan.FromSeconds(3), TimeSpan.FromSeconds(10), TimeSpan.FromSeconds(30) });
    internal static readonly TimeSpan RecentUnlockWindow = TimeSpan.FromMinutes(10);
    // Build 105 (user 11-21): a celebration must be seen, not absorbed by a load.
    // A client left open rereads (never triggers) at most this often; the wake
    // that drives it is the existing five-minute achievement sync, no new timer.
    internal static readonly TimeSpan OnlineRereadInterval = TimeSpan.FromMinutes(60);
    // One batch shows at most this many single cards; the rest become one summary.
    internal const int MaximumIndividualCards = 3;
    // SCM decides "today's holiday" by its server date (Asia/Shanghai), not the player's.
    private static readonly TimeSpan ScmDateOffset = TimeSpan.FromHours(8);
    private readonly object _gate = new(); // Task reservations only: never IO, owner reads or callbacks.
    private readonly ScmAchievementUnlockStore _store;
    private readonly Func<(BridgeAccountContext? Context, long Generation)> _owner;
    private readonly Func<BridgeAccountContext, CancellationToken, Task> _trigger;
    private readonly Func<BridgeAccountContext, CancellationToken, Task<ScmAchievementCatalog>> _read;
    private readonly Action<long, ScmAchievementItem, string> _earned;
    private readonly Action<long, IReadOnlyList<ScmAchievementUnlockStore.PendingUnlock>>? _summary;
    private readonly TimeProvider _time;
    private readonly DateTimeOffset? _trustedStartedAt;
    private readonly DateTimeOffset _wallAnchor;
    private readonly long _monotonicAnchor;
    private bool _clockConsistent = true;
    private CancellationTokenSource? _run;
    // Only the post-trigger rereads stop early on a found unlock; a page read
    // during the pre-trigger read must not cancel the day's trigger.
    private CancellationTokenSource? _rereads;
    private Task _work = Task.CompletedTask, _ioWork = Task.CompletedTask;
    private Task? _retirement;
    private long _epoch;
    private volatile bool _disposed;
    // Background read schedule per account for this process; serial worker only.
    // A read is reserved before it starts, so a failure also waits (R1 P2), and
    // an A→B→A switch keeps A's last read time.
    private readonly Dictionary<BridgeAccountContext, (long At, bool Succeeded)> _reads = new();
    internal static readonly TimeSpan FailedReadRetry = TimeSpan.FromMinutes(15);

    internal ScmAchievementUnlockRuntime(string root, Func<(BridgeAccountContext? Context, long Generation)> owner,
        Func<BridgeAccountContext, CancellationToken, Task> trigger,
        Func<BridgeAccountContext, CancellationToken, Task<ScmAchievementCatalog>> read,
        Action<long, ScmAchievementItem, string> earned, TimeProvider? time = null, DateTimeOffset? trustedStartedAt = null,
        Action<long, IReadOnlyList<ScmAchievementUnlockStore.PendingUnlock>>? summary = null)
    {
        _store = new(root); _owner = owner; _trigger = trigger; _read = read; _earned = earned; _summary = summary;
        _time = time ?? TimeProvider.System; _trustedStartedAt = trustedStartedAt;
        _wallAnchor = _time.GetUtcNow(); _monotonicAnchor = _time.GetTimestamp();
    }
    private bool Current(BridgeAccountContext context, long generation, long epoch) =>
        !_disposed && Volatile.Read(ref _epoch) == epoch && _owner() == (context, generation);

    // One explicit work owner serializes persistence and delivery. Reserving a
    // slot never runs its body under _gate. Invalidation does not wait for IO.
    private Task<T> Queue<T>(Func<T> operation)
    {
        lock (_gate)
        {
            if (_disposed) return Task.FromCanceled<T>(new CancellationToken(true));
            var previous = _ioWork;
            var next = Task.Run(async () => {
                try { await previous.ConfigureAwait(false); } catch { /* Each caller owns its failure. */ }
                return operation();
            });
            _ioWork = next;
            return next;
        }
    }
    internal void Wake()
    {
        var captured = _owner();
        if (captured.Context is not { IsComplete: true } context) return;
        CancellationTokenSource? previous;
        lock (_gate)
        {
            if (_disposed || !_work.IsCompleted) return;
            previous = _run; var run = _run = new(); var epoch = _epoch;
            _work = Task.Run(() => ProbeAsync(context, captured.Generation, epoch, run.Token));
        }
        previous?.Dispose();
    }
    internal async Task<bool> ObserveAsync(BridgeAccountContext context, long generation, ScmAchievementCatalog catalog, bool offline = false)
    {
        catalog.Validate(); var copy = catalog.Copy(); var epoch = Volatile.Read(ref _epoch);
        // Only a reread batch that existed when this observation began may be
        // stopped by it; a later batch has not read its trigger's result (R2 P3).
        CancellationTokenSource? batch; lock (_gate) batch = _epoch == epoch ? _rereads : null;
        var found = await Queue(() => ObserveCore(context, generation, epoch, copy, offline)).ConfigureAwait(false);
        if (found && batch is not null) CancelRereads(batch); // No state lock or serial reservation is held here.
        return found;
    }
    private bool Recent(ScmAchievementItem item)
    {
        var elapsed = _time.GetElapsedTime(_monotonicAnchor);
        if (elapsed < TimeSpan.Zero || (_time.GetUtcNow() - (_wallAnchor + elapsed)).Duration() > TimeSpan.FromSeconds(2))
            _clockConsistent = false;
        // ReadAtUtc is a client projection, not authenticated server time.
        // Production has no trusted start anchor; the stored baseline decides there.
        return _clockConsistent && _trustedStartedAt is { } start &&
            (_wallAnchor - start).Duration() <= TimeSpan.FromSeconds(2) &&
            item.UnlockedAtUtc is { } at && at > start - RecentUnlockWindow && at <= start + elapsed;
    }
    private bool ObserveCore(BridgeAccountContext context, long generation, long epoch, ScmAchievementCatalog catalog, bool offline)
    {
        bool IsCurrent() => Current(context, generation, epoch);
        if (!IsCurrent()) return false;
        ScmAchievementUnlockStore.State saved;
        List<ScmAchievementUnlockStore.PendingUnlock> pending;
        var found = false;
        using (var lease = _store.Open(context))
        {
            saved = lease.Read(); var confirmed = saved.Confirmed.ToHashSet(StringComparer.Ordinal);
            // Only an account's very first sync is silent (so history never floods
            // in). After it, a new process, an account return or a first read after
            // a closed client all celebrate what this account has not seen yet.
            var baseline = ScmAchievementUnlockStore.HasBaseline(saved);
            pending = ScmAchievementUnlockStore.Unshown(saved).ToList();
            foreach (var item in catalog.Items.Where(i => i.Unlocked).OrderBy(i => i.DisplayOrder))
            {
                if (!confirmed.Add(item.Id)) continue;
                if (baseline || !offline && Recent(item))
                {
                    pending.Add(new(saved.OwnerHash + ":" + item.Id, ScmAchievementUnlockStore.ForCard(item, _time.GetUtcNow()))); found |= !offline;
                }
            }
            saved = saved with { Confirmed = confirmed.Order(StringComparer.Ordinal).ToArray(), Pending = pending.ToArray(), Baseline = true };
            lease.Save(saved, IsCurrent);
        }
        if (!offline) _reads[context] = (_time.GetTimestamp(), true);
        if (offline) return false;
        Deliver(generation, pending, IsCurrent);
        return found;
    }
    // Pending stays durable until a receiver reports the card's visible dwell
    // (AchievementCelebration.MarkPresented). Handing a card over is not seeing it.
    private void Deliver(long generation, IReadOnlyList<ScmAchievementUnlockStore.PendingUnlock> pending, Func<bool> isCurrent)
    {
        var single = _summary is null || pending.Count <= MaximumIndividualCards + 1 ? pending.Count : MaximumIndividualCards;
        for (var i = 0; i < single; i++)
        {
            if (!isCurrent()) return;
            try { _earned(generation, pending[i].Item, pending[i].Receipt); }
            catch (Exception) { } // Keep failed items pending and continue their siblings.
        }
        if (single < pending.Count && isCurrent())
        {
            try { _summary!(generation, pending.Skip(single).ToArray()); }
            catch (Exception) { }
        }
    }
    // Stored cards not yet shown (an earlier process, an account return) go to
    // the receiver without waiting for an SCM read.
    private bool DrainCore(BridgeAccountContext context, long generation, long epoch)
    {
        bool IsCurrent() => Current(context, generation, epoch);
        if (!IsCurrent()) return false;
        ScmAchievementUnlockStore.PendingUnlock[] pending;
        using (var lease = _store.Open(context)) pending = ScmAchievementUnlockStore.Unshown(lease.Read());
        if (pending.Length > 0) Deliver(generation, pending, IsCurrent);
        return true;
    }
    // Reserves a background read when due: none yet in this process for this
    // account, an hour after a good read, or 15 minutes after a failed attempt.
    private bool ReserveRead(BridgeAccountContext context, long generation, long epoch)
    {
        if (!Current(context, generation, epoch)) return false;
        var now = _time.GetTimestamp();
        if (_reads.TryGetValue(context, out var last) &&
            _time.GetElapsedTime(last.At, now) < (last.Succeeded ? OnlineRereadInterval : FailedReadRetry)) return false;
        _reads[context] = (now, false);
        return true;
    }
    // Whether today's SCM date is still unclaimed, and whether this account has
    // had its first (silent) sync stored.
    private (bool Open, bool Baseline) DateState(BridgeAccountContext context, long generation, long epoch)
    {
        if (!Current(context, generation, epoch)) return (false, false);
        using var lease = _store.Open(context); var saved = lease.Read();
        var date = DateOnly.FromDateTime(_time.GetUtcNow().ToOffset(ScmDateOffset).DateTime);
        return (!saved.TriggerDates.Contains(date), ScmAchievementUnlockStore.HasBaseline(saved));
    }
    private async Task ProbeAsync(BridgeAccountContext context, long generation, long epoch, CancellationToken token)
    {
        bool IsCurrent() => !token.IsCancellationRequested && Current(context, generation, epoch);
        async Task ReadOnceAsync()
        {
            try
            {
                var catalog = await _read(context, token).ConfigureAwait(false);
                if (IsCurrent()) await ObserveAsync(context, generation, catalog).ConfigureAwait(false);
            }
            catch (Exception failure) when (Recoverable(failure) && IsCurrent())
            {
                // The 15-minute retry counts from the failure, not the request start (R2 P2).
                try { await Queue(() => { if (Current(context, generation, epoch)) _reads[context] = (_time.GetTimestamp(), false); return true; }).ConfigureAwait(false); }
                catch (OperationCanceledException) { }
            }
        }
        try
        {
            await Queue(() => DrainCore(context, generation, epoch)).ConfigureAwait(false);
            if (!IsCurrent()) return;
            var state = await Queue(() => DateState(context, generation, epoch)).ConfigureAwait(false);
            if (!IsCurrent()) return;
            if (!state.Open)
            {
                // A new process reads once (catching up on unlocks while the client
                // was closed); a client left open rereads hourly. Never a trigger.
                if (await Queue(() => ReserveRead(context, generation, epoch)).ConfigureAwait(false)) await ReadOnceAsync().ConfigureAwait(false);
                return;
            }
            if (!state.Baseline)
            {
                // R1 P1: the account's first sync must be stored before the trigger,
                // or the trigger's unlocks would later be absorbed as history. A
                // failed read leaves today's date unclaimed for a later attempt.
                if (!await Queue(() => ReserveRead(context, generation, epoch)).ConfigureAwait(false)) return;
                await ReadOnceAsync().ConfigureAwait(false);
                if (!IsCurrent() || !(await Queue(() => DateState(context, generation, epoch)).ConfigureAwait(false)).Baseline) return;
            }
            var claimed = await Queue(() => {
                if (!IsCurrent()) return false;
                using var lease = _store.Open(context); var saved = lease.Read();
                var date = DateOnly.FromDateTime(_time.GetUtcNow().ToOffset(ScmDateOffset).DateTime);
                // The commit point itself enforces the stored first sync (R1 P1, R2).
                if (saved.TriggerDates.Contains(date) || !ScmAchievementUnlockStore.HasBaseline(saved)) return false;
                lease.Save(saved with { TriggerDates = [.. saved.TriggerDates, date] }, IsCurrent);
                return true;
            }).ConfigureAwait(false);
            if (!claimed || !IsCurrent()) return;
            // With a stored baseline, whatever the trigger unlocks is new to the
            // rereads below and celebrated (no page needs to be opened).
            await _trigger(context, token).ConfigureAwait(false);
            var triggeredAt = _time.GetTimestamp();
            CancellationTokenSource rereads;
            lock (_gate)
            {
                if (_disposed || _epoch != epoch) return;
                rereads = _rereads = CancellationTokenSource.CreateLinkedTokenSource(token);
            }
            try
            {
                var rereadToken = rereads.Token;
                foreach (var offset in RereadOffsets.Take(MaximumRereads))
                {
                    var remaining = offset - _time.GetElapsedTime(triggeredAt);
                    if (remaining > TimeSpan.Zero) await Task.Delay(remaining, _time, rereadToken).ConfigureAwait(false);
                    if (!IsCurrent() || rereadToken.IsCancellationRequested) return;
                    try
                    {
                        var catalog = await _read(context, rereadToken).ConfigureAwait(false);
                        if (!IsCurrent()) return;
                        if (await ObserveAsync(context, generation, catalog).ConfigureAwait(false)) return;
                    }
                    catch (Exception failure) when (Recoverable(failure) && IsCurrent() && !rereadToken.IsCancellationRequested) { }
                }
            }
            finally
            {
                lock (_gate) if (ReferenceEquals(_rereads, rereads)) _rereads = null;
                rereads.Dispose();
            }
        }
        catch (Exception failure) when (Recoverable(failure)) { }
    }
    private static bool Recoverable(Exception failure) => failure is IOException or UnauthorizedAccessException or
        InvalidOperationException or HttpRequestException or OperationCanceledException or System.Text.Json.JsonException or
        Account.AccountBridgeHostException or Auth.ScmApiAuthenticationException or Auth.ScmApiForbiddenException or
        Auth.ScmApiProtocolException or Auth.ScmApiUnavailableException;
    private static void Cancel(CancellationTokenSource? run)
    {
        try { run?.Cancel(); } catch (ObjectDisposedException) { } catch (AggregateException) { }
    }
    private void CancelRereads(CancellationTokenSource batch)
    {
        bool live; lock (_gate) live = ReferenceEquals(_rereads, batch);
        if (live) Cancel(batch);
    }
    internal void Invalidate(long generation)
    {
        CancellationTokenSource? run; Task work;
        lock (_gate) { if (_disposed) return; _epoch++; run = _run; work = _work; }
        Cancel(run);
        _ = RestartAfterDrainAsync(work);
    }
    private async Task RestartAfterDrainAsync(Task work) { try { await work.ConfigureAwait(false); } finally { Wake(); } }
    internal Task RetireAsync()
    {
        TaskCompletionSource completion; CancellationTokenSource? run; Task work, io;
        lock (_gate)
        {
            if (_retirement is not null) return _retirement;
            _disposed = true; _epoch++; run = _run; work = _work; io = _ioWork;
            completion = new(TaskCreationOptions.RunContinuationsAsynchronously); _retirement = completion.Task;
        }
        Cancel(run);
        _ = DrainAsync(); return completion.Task;
        async Task DrainAsync()
        {
            try { await Task.WhenAll(work, io).ConfigureAwait(false); }
            catch (OperationCanceledException) { run?.Dispose(); completion.TrySetResult(); return; }
            catch (Exception error) { run?.Dispose(); completion.TrySetException(error); return; }
            run?.Dispose(); completion.TrySetResult();
        }
    }
    internal Task WaitForIdleAsync() { lock (_gate) return Task.WhenAll(_work, _ioWork); }
    public void Dispose() => _ = RetireAsync();
}
