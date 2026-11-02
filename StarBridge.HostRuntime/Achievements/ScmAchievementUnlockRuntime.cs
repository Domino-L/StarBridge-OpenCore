using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Achievements;

internal sealed class ScmAchievementUnlockRuntime : IDisposable
{
    internal const int MaximumRereads = 3;
    internal static readonly IReadOnlyList<TimeSpan> RereadOffsets = Array.AsReadOnly(new[] {
        TimeSpan.FromSeconds(3), TimeSpan.FromSeconds(10), TimeSpan.FromSeconds(30) });
    internal static readonly TimeSpan RecentUnlockWindow = TimeSpan.FromMinutes(10);
    // SCM decides "today's holiday" by its server date (Asia/Shanghai), not the player's.
    private static readonly TimeSpan ScmDateOffset = TimeSpan.FromHours(8);
    private readonly object _gate = new(); // Task reservations only: never IO, owner reads or callbacks.
    private readonly ScmAchievementUnlockStore _store;
    private readonly Func<(BridgeAccountContext? Context, long Generation)> _owner;
    private readonly Func<BridgeAccountContext, CancellationToken, Task> _trigger;
    private readonly Func<BridgeAccountContext, CancellationToken, Task<ScmAchievementCatalog>> _read;
    private readonly Action<long, ScmAchievementItem, string> _earned;
    private readonly TimeProvider _time;
    private readonly DateTimeOffset? _trustedStartedAt;
    private readonly DateTimeOffset _wallAnchor;
    private readonly long _monotonicAnchor;
    private bool _clockConsistent = true;
    private CancellationTokenSource? _run;
    private Task _work = Task.CompletedTask, _ioWork = Task.CompletedTask;
    private Task? _retirement;
    private long _epoch;
    private volatile bool _disposed;
    // Only the serial IO worker can mutate online observation state.
    private (BridgeAccountContext? Context, long Generation, long Epoch) _observed;
    private bool _hasOnlineRead;

    internal ScmAchievementUnlockRuntime(string root, Func<(BridgeAccountContext? Context, long Generation)> owner,
        Func<BridgeAccountContext, CancellationToken, Task> trigger,
        Func<BridgeAccountContext, CancellationToken, Task<ScmAchievementCatalog>> read,
        Action<long, ScmAchievementItem, string> earned, TimeProvider? time = null, DateTimeOffset? trustedStartedAt = null)
    {
        _store = new(root); _owner = owner; _trigger = trigger; _read = read; _earned = earned;
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
        var found = await Queue(() => ObserveCore(context, generation, epoch, copy, offline)).ConfigureAwait(false);
        if (found) CancelRereads(epoch); // No state lock or serial reservation is held here.
        return found;
    }
    private bool Recent(ScmAchievementItem item)
    {
        var elapsed = _time.GetElapsedTime(_monotonicAnchor);
        if (elapsed < TimeSpan.Zero || (_time.GetUtcNow() - (_wallAnchor + elapsed)).Duration() > TimeSpan.FromSeconds(2))
            _clockConsistent = false;
        // ReadAtUtc is a client projection, not authenticated server time.
        // Production has no trusted start anchor, so first sync stays silent.
        return _clockConsistent && _trustedStartedAt is { } start &&
            (_wallAnchor - start).Duration() <= TimeSpan.FromSeconds(2) &&
            item.UnlockedAtUtc is { } at && at > start - RecentUnlockWindow && at <= start + elapsed;
    }
    private bool ObserveCore(BridgeAccountContext context, long generation, long epoch, ScmAchievementCatalog catalog, bool offline)
    {
        bool IsCurrent() => Current(context, generation, epoch);
        if (!IsCurrent()) return false;
        var captured = (context, generation, epoch);
        if (_observed != captured) { _observed = captured; _hasOnlineRead = false; }
        ScmAchievementUnlockStore.State saved;
        List<ScmAchievementUnlockStore.PendingUnlock> pending;
        var found = false;
        using (var lease = _store.Open(context))
        {
            saved = lease.Read(); var confirmed = saved.Confirmed.ToHashSet(StringComparer.Ordinal);
            pending = (saved.Pending ?? []).ToList();
            foreach (var item in catalog.Items.Where(i => i.Unlocked).OrderBy(i => i.DisplayOrder))
            {
                if (!confirmed.Add(item.Id)) continue;
                if (!offline && (_hasOnlineRead || Recent(item)))
                {
                    var stable = item with { UnlockedAtUtc = item.UnlockedAtUtc ?? _time.GetUtcNow(), ImageUrl = null };
                    pending.Add(new(saved.OwnerHash + ":" + item.Id, stable)); found = true;
                }
            }
            saved = saved with { Confirmed = confirmed.Order(StringComparer.Ordinal).ToArray(), Pending = pending.ToArray() };
            lease.Save(saved, IsCurrent);
        }
        if (!offline) _hasOnlineRead = true;
        if (offline) return false;
        // Observation is durable. Consumption requires a per-item receipt.
        foreach (var entry in pending)
        {
            if (!IsCurrent()) break;
            try { _earned(generation, entry.Item, entry.Receipt); }
            catch (Exception) { continue; } // Keep failed items and continue their siblings.
            if (!IsCurrent()) break;
            using var acknowledgement = _store.Open(context);
            saved = acknowledgement.Read();
            saved = saved with { Pending = (saved.Pending ?? []).Where(p => p.Receipt != entry.Receipt).ToArray() };
            acknowledgement.Save(saved, IsCurrent);
        }
        return found;
    }
    private async Task ProbeAsync(BridgeAccountContext context, long generation, long epoch, CancellationToken token)
    {
        bool IsCurrent() => !token.IsCancellationRequested && Current(context, generation, epoch);
        try
        {
            var claimed = await Queue(() => {
                if (!IsCurrent()) return false;
                using var lease = _store.Open(context); var saved = lease.Read();
                var date = DateOnly.FromDateTime(_time.GetUtcNow().ToOffset(ScmDateOffset).DateTime);
                if (saved.TriggerDates.Contains(date)) return false;
                lease.Save(saved with { TriggerDates = [.. saved.TriggerDates, date] }, IsCurrent);
                return true;
            }).ConfigureAwait(false);
            if (!claimed || !IsCurrent()) return;
            await _trigger(context, token).ConfigureAwait(false);
            var triggeredAt = _time.GetTimestamp();
            foreach (var offset in RereadOffsets.Take(MaximumRereads))
            {
                var remaining = offset - _time.GetElapsedTime(triggeredAt);
                if (remaining > TimeSpan.Zero) await Task.Delay(remaining, _time, token).ConfigureAwait(false);
                if (!IsCurrent()) return;
                try
                {
                    var catalog = await _read(context, token).ConfigureAwait(false);
                    if (!IsCurrent()) return;
                    if (await ObserveAsync(context, generation, catalog).ConfigureAwait(false)) return;
                }
                catch (Exception failure) when (Recoverable(failure) && IsCurrent()) { }
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
    private void CancelRereads(long epoch) { CancellationTokenSource? run; lock (_gate) run = _epoch == epoch ? _run : null; Cancel(run); }
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
