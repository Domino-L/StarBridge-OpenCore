using StarBridge.Core.Events;
using StarBridge.HostRuntime.Support;

namespace StarBridge.HostRuntime.Overlay;

public sealed record LocalGameOverlayNotice(string Id, string Type, LifeEventContext Context, Func<bool> IsCurrent,
    string? DisplayValue = null, string? DisplayPlayer = null);
public interface ILocalGameOverlayEventSink
{
    ValueTask<bool> TryPresentLocalGameEventAsync(LocalGameOverlayNotice notice, CancellationToken cancellation);
}

/// <summary>Live accepted local parser events only. No journal replay, second watcher, upload or account request.</summary>
public sealed class LocalGameOverlayEventSource : IDisposable
{
    private readonly LocalGameEventJournal _journal;
    private readonly ILocalGameOverlayEventSink _sink;
    private readonly Func<long> _generation;
    private readonly TimeProvider _time;
    private readonly CancellationTokenSource _stop = new();
    private readonly IDisposable _subscription;
    private volatile bool _disposed;

    public LocalGameOverlayEventSource(LocalGameEventJournal journal, ILocalGameOverlayEventSink sink, Func<long> generation,
        TimeProvider? time = null)
    {
        _journal = journal; _sink = sink; _generation = generation; _time = time ?? TimeProvider.System;
        _subscription = journal.SubscribeNewEntries(Observe);
    }

    private void Observe(LocalEventEntry entry)
    {
        var category = SharedActivityEvent.Category(entry.EventType);
        // Location already has a direct local-snapshot path (including provisional
        // arrival/confirmation merging). Do not duplicate that card with journal output.
        if (_disposed || category is SharedActivityEventTypes.None or SharedActivityEventTypes.Location) return;
        var generation = _generation();
        var clearRevision = _journal.ClearRevision;
        bool Current() => !_disposed && !_stop.IsCancellationRequested && _generation() == generation &&
            _journal.ClearRevision == clearRevision && entry.OccurredAt <= _time.GetUtcNow().AddSeconds(15) &&
            entry.OccurredAt >= _time.GetUtcNow().AddMinutes(-2);
        if (Current()) _ = DeliverAsync(new(entry.Id, entry.EventType, entry.LifeContext, Current, entry.DisplayValue, entry.DisplayPlayer));
    }

    private async Task DeliverAsync(LocalGameOverlayNotice notice)
    {
        try { await _sink.TryPresentLocalGameEventAsync(notice, _stop.Token).ConfigureAwait(false); }
        catch { /* A closed/failed presentation must not break journal append or replay after reopening. */ }
    }

    public void Dispose() { _disposed = true; _subscription.Dispose(); _stop.Cancel(); }
}
