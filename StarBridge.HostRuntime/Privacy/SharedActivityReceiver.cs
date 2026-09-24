using StarBridge.Core.Events;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Privacy;

public sealed record SharedActivityNotice(string Callsign, SharedActivityEvent Event, Func<bool> IsCurrent);
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

// Receives only the currently authorized overlay context. Switching context,
// reconnecting or changing accounts establishes a new baseline without alerts.
internal sealed class SharedActivityReceiver(ISharedActivityReader reader, ISharedActivitySink sink,
    Func<(BridgeAccountContext? Owner, long Generation, string? Scope, string? Id)> current) : IDisposable
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly CancellationTokenSource _lifetime = new();
    private ITimer? _timer;
    private HashSet<string> _seen = [];
    private HashSet<string> _available = [];
    private (BridgeAccountContext? Owner, long Generation, string? Scope, string? Id) _context;
    private bool _baseline, _disposed;
    private long _epoch;
    internal void Start() => _timer ??= TimeProvider.System.CreateTimer(_ => _ = TickAsync(), null, TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(5));
    internal async Task TickAsync()
    {
        if (_disposed || !await _gate.WaitAsync(0)) return;
        try
        {
            var context = current();
            if (context != _context) { _context = context; _seen.Clear(); _baseline = false; _epoch++; }
            if (context.Owner is null || context.Scope is null || context.Id is null) return;
            var result = await reader.ReadActivityAsync(context.Owner, context.Generation, context.Scope, context.Id, _lifetime.Token);
            if (_disposed || current() != context) return;
            var epoch = _epoch;
            var expires = DateTimeOffset.UtcNow.AddSeconds(7);
            var entries = result.Publishers.SelectMany(p => p.Events.Select(e => (Key: p.AccountId + ":" + e.Id, p.Callsign, Event: e))).ToArray();
            Volatile.Write(ref _available, entries.Select(e => e.Key).ToHashSet(StringComparer.Ordinal));
            var notices = _baseline ? entries.Where(e => !_seen.Contains(e.Key)).TakeLast(16).ToArray() : [];
            _seen.UnionWith(entries.Select(e => e.Key));
            _baseline = true;
            if (_seen.Count > 16384) { _seen.Clear(); _baseline = false; return; }
            foreach (var entry in notices)
            {
                bool Valid() => !_disposed && epoch == _epoch && current() == context && DateTimeOffset.UtcNow < expires &&
                    Volatile.Read(ref _available).Contains(entry.Key);
                if (!Valid()) return;
                await sink.TryPresentActivityAsync(new(entry.Callsign, entry.Event, Valid), _lifetime.Token);
            }
        }
        catch { _baseline = false; _seen.Clear(); _epoch++; }
        finally { _gate.Release(); }
    }
    public void Dispose() { _disposed = true; _epoch++; _timer?.Dispose(); _lifetime.Cancel(); }
}
