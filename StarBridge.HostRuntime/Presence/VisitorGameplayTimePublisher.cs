using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Presence;

public readonly record struct VisitorGameplayTime(long Seconds, long? SourceRevision)
{
    internal const long MaximumRevision = 9_007_199_254_740_991;
    internal bool IsValid => Seconds is >= 0 and <= 1_000_000_000 &&
        SourceRevision is null or (>= 0 and <= MaximumRevision);
}

public enum VisitorGameplayTimeOutcome
{
    Ok, Invalid, StaleRevision, AuthorizationRejected, Unavailable, TemporaryFailure, ProtocolError
}

public sealed record VisitorGameplayTimeResult(VisitorGameplayTimeOutcome Outcome,
    string? Field = null, long? StoredRevision = null, TimeSpan? RetryAfter = null, DateTimeOffset? RetryAt = null)
{
    internal static string? SafeField(string? field) =>
        field is "schemaVersion" or "playTimeSeconds" or "sourceRevision" ? field : null;
}

public interface IVisitorGameplayTimeRemote
{
    bool Supports(BridgeAccountContext owner, long generation);
    Task<VisitorGameplayTimeResult> WriteAsync(BridgeAccountContext owner, long generation,
        VisitorGameplayTime value, CancellationToken token);
}

internal sealed class VisitorGameplayTimePublisher(IVisitorGameplayTimeRemote remote, VisitorGameplayTimeReceiptStore receipts,
    Func<(BridgeAccountContext? Context, long Generation)> current, TimeProvider time) : IDisposable
{
    private static readonly TimeSpan Debounce = TimeSpan.FromSeconds(30);
    private static readonly TimeSpan[] Backoff = [TimeSpan.FromMinutes(1), TimeSpan.FromMinutes(5), TimeSpan.FromMinutes(30)];
    private readonly object _gate = new();
    private Session? _session;
    private ITimer? _timer;
    private bool _disposed;

    private sealed record Pending(VisitorGameplayTime Value, DateTimeOffset Due, int Retries = 0);

    private sealed class Session(BridgeAccountContext owner, long generation)
    {
        internal readonly BridgeAccountContext Owner = owner;
        internal readonly long Generation = generation;
        internal readonly CancellationTokenSource Lifetime = new();
        internal readonly HashSet<long> InvalidSeconds = [];
        internal Pending? Pending;
        internal Task? Flight;
        internal bool ReceiptLoaded;
        internal VisitorGameplayTime? LastSuccess;
        internal VisitorGameplayTime? Stale;
        internal DateTimeOffset NotBefore;
    }

    internal void Submit(BridgeAccountContext owner, long generation, VisitorGameplayTime value)
    {
        if (!value.IsValid || current() != (owner, generation) || !remote.Supports(owner, generation)) return;
        lock (_gate)
        {
            if (_disposed || current() != (owner, generation)) return;
            if (_session is not { } session || session.Owner != owner || session.Generation != generation)
            {
                InvalidateLocked();
                _session = session = new(owner, generation);
            }
            var now = time.GetUtcNow();
            if (session.Pending is { } pending && pending.Value == value &&
                (pending.Retries > 0 || pending.Due <= now)) return;
            // A pending item that Wake has not taken keeps its deadline and retry level; a later trigger only
            // replaces the value. A total that changes on every 30-second tick is still sent while the game runs,
            // even when a trigger lands after the deadline but before the timer callback.
            session.Pending = session.Pending is { } open ? open with { Value = value } : new(value, now + Debounce);
            ScheduleLocked();
        }
    }

    private void ScheduleLocked()
    {
        var delay = Timeout.InfiniteTimeSpan;
        if (_session is { Flight: null, Pending: { } pending } session)
        {
            var due = pending.Due > session.NotBefore ? pending.Due : session.NotBefore;
            var remaining = due - time.GetUtcNow();
            delay = remaining <= TimeSpan.Zero ? TimeSpan.Zero : remaining;
            // Keep delays representable by the system timer even for a long server Retry-After.
            if (delay > TimeSpan.FromDays(1)) delay = TimeSpan.FromDays(1);
            _timer ??= time.CreateTimer(_ => Wake(), null, Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
        }
        _timer?.Change(delay, Timeout.InfiniteTimeSpan);
    }

    private void Wake()
    {
        lock (_gate)
        {
            if (_disposed || _session is not { Flight: null, Pending: { } pending } session) return;
            var now = time.GetUtcNow();
            if (pending.Due > now || session.NotBefore > now)
            {
                ScheduleLocked();
                return;
            }
            session.Pending = null;
            session.Flight = Task.Run(() => SendAsync(session, pending));
        }
    }

    private bool IsCurrent(Session session) =>
        !session.Lifetime.IsCancellationRequested && current() == (session.Owner, session.Generation) &&
        remote.Supports(session.Owner, session.Generation);

    private async Task SendAsync(Session session, Pending pending)
    {
        VisitorGameplayTimeResult? result = null;
        try
        {
            if (!IsCurrent(session)) return;
            if (!session.ReceiptLoaded)
            {
                session.LastSuccess = receipts.Read(session.Owner);
                session.ReceiptLoaded = true;
            }

            var value = pending.Value;
            if (session.LastSuccess == value || session.InvalidSeconds.Contains(value.Seconds) ||
                session.Stale is { } stale && (value.SourceRevision is null || value.SourceRevision == stale.SourceRevision) ||
                !IsCurrent(session)) return;

            using var budget = CancellationTokenSource.CreateLinkedTokenSource(session.Lifetime.Token);
            budget.CancelAfter(TimeSpan.FromSeconds(10));
            result = await remote.WriteAsync(session.Owner, session.Generation, value, budget.Token).ConfigureAwait(false);
            if (!IsCurrent(session)) return;
            if (result.Outcome == VisitorGameplayTimeOutcome.Ok)
            {
                session.LastSuccess = value;
                session.Stale = null;
                receipts.Save(session.Owner, value);
            }
            if (result.Outcome == VisitorGameplayTimeOutcome.Invalid && session.InvalidSeconds.Add(value.Seconds))
            {
                var field = VisitorGameplayTimeResult.SafeField(result.Field);
                IdentityGateJournal.Event("gameplay-time-hk",
                    field is null ? "code=gameplay_time.invalid" : $"code=gameplay_time.invalid field={field}");
            }
            if (result.Outcome == VisitorGameplayTimeOutcome.StaleRevision) session.Stale = value;
        }
        catch (Exception error) when (error is HttpRequestException or IOException or OperationCanceledException or TimeoutException)
        {
            result ??= new(VisitorGameplayTimeOutcome.TemporaryFailure);
        }
        catch (Exception error) when (error is not OutOfMemoryException)
        {
            // A stale admission or a persistence failure is isolated from the Japan publisher.
        }
        finally
        {
            lock (_gate)
            {
                session.Flight = null;
                if (ReferenceEquals(_session, session))
                {
                    if (result?.Outcome == VisitorGameplayTimeOutcome.TemporaryFailure)
                        RetryLocked(session, pending, result);
                    ScheduleLocked();
                }
            }
        }
    }

    private void RetryLocked(Session session, Pending failed, VisitorGameplayTimeResult result)
    {
        var now = time.GetUtcNow();
        var due = now;
        if (result.RetryAfter is { } delta && delta > TimeSpan.Zero)
            due = now + (delta > DateTimeOffset.MaxValue - now ? DateTimeOffset.MaxValue - now : delta);
        if (result.RetryAt is { } retryAt && retryAt > due) due = retryAt;
        if (failed.Retries < Backoff.Length)
        {
            var backoff = now + Backoff[failed.Retries];
            if (backoff > due) due = backoff;
            // A newer value that arrived during the attempt is sent instead, at this retry level.
            session.Pending = new(session.Pending?.Value ?? failed.Value, due, failed.Retries + 1);
        }
        else
        {
            // The cycle is spent: anything queued during the last attempt belongs to it too (any value),
            // and the next trigger after this point starts a new cycle (contract: "最多 3 次，之后等下次触发").
            session.Pending = null;
        }
        session.NotBefore = due;
    }

    internal void Invalidate()
    {
        lock (_gate) InvalidateLocked();
    }

    private void InvalidateLocked()
    {
        if (_session is { } session)
        {
            _session = null;
            _ = CancelAndDisposeAsync(session.Lifetime, session.Flight);
        }
        _timer?.Change(Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
    }

    private static async Task CancelAndDisposeAsync(CancellationTokenSource lifetime, Task? flight)
    {
        try { await lifetime.CancelAsync().ConfigureAwait(false); }
        catch (AggregateException) { }
        try { if (flight is not null) await flight.ConfigureAwait(false); }
        finally { lifetime.Dispose(); }
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed) return;
            _disposed = true;
            InvalidateLocked();
            _timer?.Dispose();
            _timer = null;
        }
    }
}
