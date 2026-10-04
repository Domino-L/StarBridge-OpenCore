using StarBridge.Core.Events;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Privacy;

public sealed record SharedActivityNotice(string Callsign, SharedActivityEvent Event, Func<bool> IsCurrent)
{
    public string? PublisherKey { get; init; }
    // Host-observed read scope, never supplied by a Flutter preview.
    public string? SourceKey { get; init; }
}
public interface ISharedActivitySink
{
    ValueTask<bool> TryPresentActivityAsync(SharedActivityNotice notice, CancellationToken token);
}
internal sealed record SharedActivityPublisher(string AccountId, string Callsign, SharedActivityEvent[] Events);
internal sealed record SharedActivityRead(int SchemaVersion, DateTimeOffset ObservedAt, SharedActivityPublisher[] Publishers);
internal interface ISharedActivityReader
{
    Task<SharedActivityRead> ReadActivityAsync(BridgeAccountContext owner, long generation, string scope, string id, CancellationToken token);
}

// The membership stamp distinguishes rejoining the same source from an ordinary
// payload update. Neither a saved binding nor a resource key grants authority.
internal sealed record SharedActivitySubscription(BridgeAccountContext? Owner, long Generation,
    string? Scope, string? Id, object? AuthorityStamp = null)
{
    // Validation is not subscription identity: ordinary captures construct a new
    // closure but must not replay the baseline or interrupt an in-flight read.
    internal Func<bool>? IsAuthorized { get; init; }
    public bool Equals(SharedActivitySubscription? other) => other is not null &&
        Owner == other.Owner && Generation == other.Generation && Scope == other.Scope && Id == other.Id &&
        Equals(AuthorityStamp, other.AuthorityStamp);
    public override int GetHashCode() => HashCode.Combine(Owner, Generation, Scope, Id, AuthorityStamp);
}

// Receives only the currently authorized overlay context. Switching context,
// reconnecting or changing accounts establishes a new baseline without alerts.
internal sealed class SharedActivityReceiver(ISharedActivityReader reader, ISharedActivitySink sink,
    Func<SharedActivitySubscription> current, TimeProvider? clock = null) : IDisposable
{
    internal SharedActivityReceiver(ISharedActivityReader reader, ISharedActivitySink sink,
        Func<(BridgeAccountContext? Owner, long Generation, string? Scope, string? Id)> current, TimeProvider? clock = null)
        : this(reader, sink, () =>
        {
            var value = current();
            return new SharedActivitySubscription(value.Owner, value.Generation, value.Scope, value.Id);
        }, clock) { }
    private readonly TimeProvider _clock = clock ?? TimeProvider.System;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly CancellationTokenSource _lifetime = new();
    private ITimer? _timer;
    private HashSet<string> _seen = [];
    private HashSet<string> _available = [];
    private SharedActivitySubscription? _context;
    private (BridgeAccountContext? Owner, long Generation, string? Scope, string? Id) _retryScope;
    private bool _baseline, _disposed;
    private long _epoch;
    private int _failures;
    private DateTimeOffset _nextAttempt;
    internal void Start() => _timer ??= _clock.CreateTimer(_ => _ = TickAsync(), null, TimeSpan.Zero, TimeSpan.FromSeconds(1));
    private SharedActivitySubscription SafeCurrent()
    {
        try { return current(); }
        catch { return new(null, 0, null, null); }
    }
    private bool StillCurrent(SharedActivitySubscription context)
    {
        try { return !_disposed && (context.IsAuthorized?.Invoke() ?? (SafeCurrent() == context)); }
        catch { return false; }
    }
    internal async Task TickAsync()
    {
        if (_disposed || !await _gate.WaitAsync(0)) return;
        try
        {
            var context = SafeCurrent();
            if (context != _context) { _seen.Clear(); _baseline = false; _epoch++; }
            // Equality excludes the validation closure. Keep the current read's
            // probe for cancellation classification even when identity is stable.
            _context = context;
            if (context.Owner is null || context.Scope is null || context.Id is null) return;
            // Membership churn resets history, not transport backoff. A brief
            // invalid/hidden state must not accelerate retries to the same feed.
            var retryScope = (context.Owner, context.Generation, context.Scope, context.Id);
            if (retryScope != _retryScope)
            { _retryScope = retryScope; _failures = 0; _nextAttempt = default; }
            if (_timer is not null && _clock.GetUtcNow() < _nextAttempt) return;
            var result = await Overlay.OverlayDemandRead.RunAsync(token =>
                reader.ReadActivityAsync(context.Owner, context.Generation, context.Scope, context.Id, token),
                () => StillCurrent(context), _lifetime.Token);
            if (!StillCurrent(context)) return;
            _failures = 0; _nextAttempt = default;
            var epoch = _epoch;
            var expires = DateTimeOffset.UtcNow.AddSeconds(7);
            var entries = result.Publishers.SelectMany(p => p.Events.Select(e => (Key: p.AccountId + ":" + e.Id, p.Callsign,
                PublisherKey: Overlay.OverlayMemberIdentity.FromAccountId(p.AccountId), Event: e))).ToArray();
            Volatile.Write(ref _available, entries.Select(e => e.Key).ToHashSet(StringComparer.Ordinal));
            var notices = _baseline ? entries.Where(e => !_seen.Contains(e.Key)).TakeLast(16).ToArray() : [];
            _seen.UnionWith(entries.Select(e => e.Key));
            _baseline = true;
            if (_seen.Count > 16384) { _seen.Clear(); _baseline = false; return; }
            foreach (var entry in notices)
            {
                bool Valid() => epoch == _epoch && StillCurrent(context) && DateTimeOffset.UtcNow < expires &&
                    Volatile.Read(ref _available).Contains(entry.Key);
                if (!Valid()) return;
                await sink.TryPresentActivityAsync(new(entry.Callsign, entry.Event, Valid)
                {
                    PublisherKey = entry.PublisherKey,
                    SourceKey = context.Scope switch { "room" => "Room:" + context.Id, "organization" => "Community:" + context.Id, _ => null }
                }, _lifetime.Token);
            }
        }
        catch (OperationCanceledException) when (_disposed || _context is null || !StillCurrent(_context))
        {
            // Closing or changing authority is not a failing server attempt.
            _baseline = false; _seen.Clear(); _epoch++;
        }
        catch
        {
            _baseline = false; _seen.Clear(); _epoch++;
            _failures = Math.Min(4, _failures + 1);
            _nextAttempt = _clock.GetUtcNow().AddSeconds(_failures switch { 1 => 1, 2 => 3, 3 => 5, _ => 15 });
        }
        finally { _gate.Release(); }
    }
    public void Dispose() { _disposed = true; _epoch++; _timer?.Dispose(); _lifetime.Cancel(); }
}
